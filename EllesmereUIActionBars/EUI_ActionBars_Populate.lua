if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Populate.lua
--
--  Action bar spells: the EllesmereUI Builder's spells per spec and action
--  slot (the profile-root key abSpells = { [specKey] = { [slot] = spellID } }),
--  placed on the player's own bars. ns.Populate reads them for this character
--  (P.Data), lists the bars that can take them (P.Bars), finds the spell to
--  place (P.Resolve: the highest rank known on WoW Forever; on retail the
--  spell itself, else the known spell of its name), places the pages of the
--  bars the player ticks (P.Run), and with Auto Populate on places a builder
--  spell as it becomes known (P.Check), taking off the copy the game pushed
--  to its first free slot. The Choose Bars view
--  (EUI_ActionBars_PopulatePicker.lua) and the Action Bars options call it.
--
--  A bar owns fixed pages: its own page, and for Action Bar 1 also the form
--  and stance pages 7 to 9 (and 10, Moonkin Form, on a retail druid, which is
--  Action Bar 10's own page too). A ticked bar's page that holds at least one
--  builder spell ends up exactly as built; a page with none is left alone.
--  Pages 11 and 12, slots above 180 and the stance and pet bars are never
--  touched.
--
--  Per-character state, the roster's abPopulate field (never exported):
--    abPopulate[specKey] = { bars = { [barKey] = true },  -- last Populate's ticks
--                            auto = true,                 -- Auto Populate
--                            known = { [stored spell] = resolved spell or false },
--                            pushedOn = { [slot] = spell } }  -- the game's own spell on a
--                                                          -- builder button that waited
--    abPopulate.seen = { [import mark] = true }           -- popups answered
--  A stored spell with no known entry has not been seen yet: the next check
--  records it without placing it.
--
--  Cost: a profile without bar spells for this character costs two table
--  reads at login and at every Action Bars apply, nothing else: no frame, no
--  event. Events are registered only while Auto Populate is on for a spec the
--  active profile has bar spells for (the retail spec watcher), the learn
--  events only for the current spec and only once a Populate ticked bars.
--  Every event only marks work; one check a frame after it reads it, and
--  skips the spellbook walk unless the spellbook or the known builder spells
--  changed. Placing and clearing wait for combat to end and for an empty
--  cursor.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local pairs, ipairs, next, type = pairs, ipairs, next, type
local tonumber, tostring, pcall = tonumber, tostring, pcall
local floor = math.floor
local sort, wipe = table.sort, wipe
local InCombatLockdown, GetCursorInfo, ClearCursor = InCombatLockdown, GetCursorInfo, ClearCursor
local C_ActionBar, C_Spell, C_SpellBook = C_ActionBar, C_Spell, C_SpellBook
local issecretvalue = issecretvalue

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local I = ns._internals
local BAR_CONFIG, barFrames = I.BAR_CONFIG, I.barFrames

local P = {}

local IS_FOREVER = EllesmereUI.IS_FOREVER == true
local PLAYER = Enum.SpellBookSpellBank.Player
local SPELL = Enum.SpellBookItemType.Spell
-- WoW Forever only: a spellbook line of a spell the character has a higher rank of.
local LowRank = C_SpellBook.IsSpellBookItemLowRank
local MAX_SLOT = 180
-- The one WoW Forever rank family whose higher rank carries another name.
local ALIAS = { [5487] = 9634 }   -- Bear Form -> Dire Bear Form
local MAX_RECORDS = 12     -- the game's pushed copies followed at once

local _, PLAYER_CLASS = UnitClass("player")
-- A retail druid's Action Bar 1 shows Action Bar 10's page in Moonkin Form:
-- the two bars share those 12 buttons, so their ticks go together.
local MOONKIN_TIE = not IS_FOREVER and PLAYER_CLASS == "DRUID"

-- The pages each bar owns (fixed: the player's paging decides what a bar
-- shows, never which slots its tick covers).
local OWN = {}
for key, page in pairs(EAB_VTABLE.BAR_KEY_TO_PAGE) do OWN[key] = { page } end
OWN.MainBar = { 1, 7, 8, 9 }
if MOONKIN_TIE then OWN.MainBar[5] = 10 end

-- Action Bar 1's form and stance pages by name: [bonusbar:N] shows page 6 + N.
local PAGE_LABEL = {}
do
    local all = EllesmereUI.CLASS_PAGING_STATES
    local states = all and PLAYER_CLASS and all[PLAYER_CLASS]
    if states then
        for i = 1, #states do
            local macro = states[i].macro
            local n = type(macro) == "string" and macro:match("^%[bonusbar:(%d)%]$")
            if n then
                local page = 6 + tonumber(n)
                if not PAGE_LABEL[page] then PAGE_LABEL[page] = states[i].label end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Reading the profile
-------------------------------------------------------------------------------
local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == (kind or "number") then return v end
end

-- A positive whole spell ID from a number or a numeric string; nil otherwise.
local function SpellIDOf(v)
    if v == nil or issecretvalue(v) then return nil end
    local t = type(v)
    if t ~= "number" and t ~= "string" then return nil end
    local id = tonumber(v)
    if id and id > 0 and id < 2147483648 and id == floor(id) then return id end
end

local function Say(msg)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
end

-- A spec's slot table: the builder writes the spec key as a string ("71"), a
-- profile made in game may hold a number; both are one spec, the string first.
local function SpecTable(abs, id)
    local t = abs[tostring(id)]
    if type(t) == "table" and next(t) ~= nil then return t end
    local n = tonumber(id)
    t = n and abs[n]
    if type(t) == "table" and next(t) ~= nil then return t end
end

local function HasSpecTable(id, abs)
    return SpecTable(abs, id) ~= nil
end

local function ActiveProfile()
    local prof = EllesmereUI.GetActiveProfileData()
    if type(prof) == "table" then return prof end
end

local function ActiveABSpells(prof)
    local abs = prof and prof.abSpells
    if type(abs) == "table" then return abs end
end

-- This character's spec key in abs (always a string), or nil. WoW Forever:
-- the class's retail spec the store holds data under (ForeverClassSpec).
local function SpecKeyFor(abs)
    local id
    if IS_FOREVER then
        id = EllesmereUI.ForeverClassSpec(nil, HasSpecTable, abs, true)
    else
        local index = Plain(C_SpecializationInfo.GetSpecialization())
        if index and index > 0 then
            id = Plain((C_SpecializationInfo.GetSpecializationInfo(index)))
        end
    end
    if id and id > 0 and HasSpecTable(id, abs) then return tostring(id) end
end

-- The spec table, normalized: slots 1-180 off pages 11 and 12, each holding a
-- whole spell ID; anything else is ignored. A slot written both as a number
-- and as a string reads the string's spell.
local function Normalize(t, key)
    local slots, pages, n = {}, {}, 0
    for k, v in pairs(t) do
        local slot = SpellIDOf(k)
        local id = SpellIDOf(v)
        if slot and id and slot <= MAX_SLOT then
            local page = floor((slot - 1) / 12) + 1
            if page ~= 11 and page ~= 12 and (slots[slot] == nil or type(k) == "string") then
                if slots[slot] == nil then
                    n = n + 1
                    pages[page] = (pages[page] or 0) + 1
                end
                slots[slot] = id
            end
        end
    end
    if n == 0 then return nil end
    local spells, seen = {}, {}
    for _, id in pairs(slots) do
        if not seen[id] then
            seen[id] = true
            spells[#spells + 1] = id
        end
    end
    sort(spells)
    return { key = key, slots = slots, pages = pages, n = n, spells = spells }
end

-- Memo inputs: the active profile table, its abSpells table and the spec key.
-- An import replaces the profile and its abSpells whole (never edits them in
-- place), and P.Sync drops the memo when any of the three changes.
local memoProf, memoAbs, memoKey, memoData

--- The active profile's bar spells for this character's spec, normalized and
--- shared (read only): { key, slots = { [slot] = spellID }, pages = { [page]
--- = count }, n, spells = { distinct IDs, sorted } }, or nil.
function P.Data()
    local prof = ActiveProfile()
    local abs = ActiveABSpells(prof)
    if not abs then return nil end
    local key = SpecKeyFor(abs)
    if not key then return nil end
    if prof ~= memoProf or abs ~= memoAbs or key ~= memoKey then
        memoProf, memoAbs, memoKey = prof, abs, key
        memoData = Normalize(SpecTable(abs, key), key)
    end
    return memoData
end

function P.SpecKey()
    local abs = ActiveABSpells(ActiveProfile())
    return abs and SpecKeyFor(abs) or nil
end

function P.HasData()
    return P.Data() ~= nil
end

-------------------------------------------------------------------------------
--  The roster
-------------------------------------------------------------------------------
local function Roster(create)
    return EllesmereUI.CharData("abPopulate", create)
end

local function SpecState(key, create)
    local r = key and Roster(create)
    if not r then return nil end
    local st = r[key]
    if type(st) ~= "table" then
        if not create then return nil end
        st = {}
        r[key] = st
    end
    return st
end

local function ActiveMark()
    local prof = ActiveProfile()
    local mark = prof and prof._abSpellsImported
    if type(mark) == "number" then return mark end
end

-- Remembers an answered import mark; keeps the 20 newest.
local function MarkSeen(mark)
    local r = Roster(true)
    if not r then return end
    local seen = r.seen
    if type(seen) ~= "table" then
        seen = {}
        r.seen = seen
    end
    seen[mark] = true
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    if n <= 20 then return end
    local list = {}
    for k in pairs(seen) do
        if type(k) == "number" then list[#list + 1] = k else seen[k] = nil end
    end
    sort(list)
    for i = 1, #list - 20 do seen[list[i]] = nil end
end

-- The bar keys of a set that own pages (truthy values only), copied.
local function CopySet(set)
    local copy = {}
    for k, v in pairs(set) do
        if v and OWN[k] then copy[k] = true end
    end
    return copy
end

--- A copy of this spec's ticks at the last Populate; nil before one.
function P.LastBars()
    local d = P.Data()
    local st = d and SpecState(d.key, false)
    local bars = st and st.bars
    if type(bars) ~= "table" or next(bars) == nil then return nil end
    return CopySet(bars)
end

--- Auto Populate for this spec.
function P.Auto()
    local d = P.Data()
    local st = d and SpecState(d.key, false)
    return st ~= nil and st.auto == true
end

-------------------------------------------------------------------------------
--  Bars and pages
-------------------------------------------------------------------------------
local function BarOff(key)
    local db = EAB.db
    local bars = db and db.profile and db.profile.bars
    local s = bars and bars[key]
    return type(s) == "table" and s.enabled == false
end

--- The pages with bar spells that a set of bar keys covers: { [page] = true }.
--- A bar switched off in the profile covers nothing.
function P.PagesFor(set)
    local out = {}
    local d = P.Data()
    if not d or type(set) ~= "table" then return out end
    for key, on in pairs(set) do
        local own = on and OWN[key]
        if own and not BarOff(key) then
            for i = 1, #own do
                if d.pages[own[i]] then out[own[i]] = true end
            end
        end
    end
    return out
end

local function SortedPages(set)
    local list = {}
    for page in pairs(set) do list[#list + 1] = page end
    sort(list)
    return list
end

--- The bars with bar spells, in bar order: { key, label, count, pages = {
--- { page, count, label?, tie? } }, tie?, off? }. tie: the retail druid's other
--- bar of the Moonkin page; off: switched off in the profile or not built.
function P.Bars()
    local out = {}
    local d = P.Data()
    if not d then return out end
    local tie = MOONKIN_TIE and d.pages[10] ~= nil
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local own = OWN[key]
        if own then
            local pages, count = {}, 0
            for i = 1, #own do
                local page = own[i]
                local c = d.pages[page]
                if c then
                    local entry = { page = page, count = c }
                    if key == "MainBar" and page ~= 1 then
                        entry.label = PAGE_LABEL[page]
                        if page == 10 then entry.tie = "Bar10" end
                    end
                    pages[#pages + 1] = entry
                    count = count + c
                end
            end
            if #pages > 0 then
                local bar = { key = key, label = info.label, count = count, pages = pages }
                if tie and key == "MainBar" then
                    bar.tie = "Bar10"
                elseif tie and key == "Bar10" then
                    bar.tie = "MainBar"
                end
                if BarOff(key) or not barFrames[key] then bar.off = true end
                out[#out + 1] = bar
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  The resolver
-------------------------------------------------------------------------------
-- The spellbook by name, built at most once per Run and per check (the
-- caller bumps bookGen) into two kept tables. WoW Forever: name -> the
-- highest rank known. Retail: name -> the base spell of the item (an
-- override's name too, when no item of its own has it): the base is what
-- gets placed, and the game shows the replacement.
local bookTop, bookByName = {}, {}
local bookGen, bookBuilt = 0, -1

local function Book()
    if bookBuilt == bookGen then return end
    bookBuilt = bookGen
    wipe(bookTop)
    wipe(bookByName)
    local lines = Plain(C_SpellBook.GetNumSpellBookSkillLines()) or 0
    for line = 1, lines do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        local first = li and not li.offSpecID and Plain(li.itemIndexOffset)
        local count = first and Plain(li.numSpellBookItems)
        if count then
            for slot = first + 1, first + count do
                local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(slot, PLAYER)
                if Plain(itemType) == SPELL
                   and Plain(C_SpellBook.IsSpellBookItemPassive(slot, PLAYER), "boolean") == false
                   and (not LowRank or Plain(LowRank(slot, PLAYER), "boolean") == false) then
                    local base, over = Plain(actionID), Plain(spellID)
                    if IS_FOREVER then
                        local id = over or base
                        local name = id and Plain(C_Spell.GetSpellName(id), "string")
                        if name then bookTop[name] = id end
                    elseif base then
                        local name = Plain(C_Spell.GetSpellName(base), "string")
                        if name then bookByName[name] = base end
                        if over and over ~= base then
                            local oname = Plain(C_Spell.GetSpellName(over), "string")
                            if oname and bookByName[oname] == nil then bookByName[oname] = base end
                        end
                    end
                end
            end
        end
    end
end

local function Known(id)
    return Plain(C_SpellBook.IsSpellKnown(id, PLAYER), "boolean") == true
end

local function KnownByID(id)
    if IS_FOREVER then return Known(id) end
    return Plain(C_SpellBook.IsSpellKnownOrInSpellBook(id, PLAYER, true), "boolean") == true
end

local function Resolve(v)
    local id = SpellIDOf(v)
    if not id then return nil end
    if IS_FOREVER then
        local hi = ALIAS[id]
        if hi and Known(hi) then return hi end
        local name = Plain(C_Spell.GetSpellName(id), "string")
        if not name then return nil end
        Book()
        local top = bookTop[name]
        if top then return top end
        if Known(id) then return id end   -- a known spell on no skill line
        return nil
    end
    if KnownByID(id) then return id end
    local name = Plain(C_Spell.GetSpellName(id), "string")
    if not name then return nil end
    Book()
    return bookByName[name]   -- a talent choice's other spell, a variant of the spell
end

--- The spell to place for a stored spell ID now (numbers or numeric strings),
--- or nil while the character knows none.
function P.Resolve(spellID)
    bookGen = bookGen + 1
    return Resolve(spellID)
end

-------------------------------------------------------------------------------
--  Slots
-------------------------------------------------------------------------------
-- "empty", "spell" + its spell ID, "other" (macro, item, flyout, mount...) or
-- "secret" (unreadable: left alone).
local function ReadSlot(slot)
    local has = C_ActionBar.HasAction(slot)
    if issecretvalue(has) then return "secret" end
    if not has then return "empty" end
    local kind, id, sub = GetActionInfo(slot)
    if issecretvalue(kind) or issecretvalue(id) or issecretvalue(sub) then return "secret" end
    if kind == "spell" and type(id) == "number" then return "spell", id end
    return "other"
end

-- Whether a slot's spell cur shows spell t (itself, or a talent's replacement).
local function Holds(cur, t)
    if cur == t then return true end
    if Plain(C_Spell.GetBaseSpell(cur)) == t then return true end
    return Plain(C_Spell.GetOverrideSpell(t)) == cur
end

local function SameName(a, b)
    local na = Plain(C_Spell.GetSpellName(a), "string")
    return na ~= nil and na == Plain(C_Spell.GetSpellName(b), "string")
end

-- WoW Forever: cur is another rank of t's spell.
local function SameFamily(cur, t)
    return ALIAS[cur] == t or ALIAS[t] == cur or SameName(cur, t)
end

-- WoW Forever: whether the game says a button's spell is the top rank (no
-- answer counts as not, so the replace goes ahead). Guards a check whose
-- spellbook read listed a lower rank as the top.
local function TopRank(id)
    local f = C_ActionBar.IsHighestSpellRank
    return f ~= nil and Plain(f(id), "boolean") == true
end

local function SameSpell(a, b)
    return Holds(a, b) or Holds(b, a) or SameName(a, b)
end

-- Out of combat with an empty cursor only (the callers make sure).
local function Place(slot, id)
    C_Spell.PickupSpell(id)
    if not GetCursorInfo() then return false end
    PlaceAction(slot)
    ClearCursor()
    local kind, cur = ReadSlot(slot)
    return kind == "spell" and Holds(cur, id)
end

local function Clear(slot)
    PickupAction(slot)
    ClearCursor()
    return Plain(C_ActionBar.HasAction(slot), "boolean") == false
end

-- Every stored spell of the data -> the spell placed for it now, or false.
local function Baseline(st, d)
    local known = st.known
    if type(known) ~= "table" then
        known = {}
        st.known = known
    else
        wipe(known)
    end
    local spells = d.spells
    for i = 1, #spells do known[spells[i]] = Resolve(spells[i]) or false end
end

-------------------------------------------------------------------------------
--  Populate
-------------------------------------------------------------------------------
local function RunLoop(d, pages)
    local placed, cleared, waiting, skipped = 0, 0, 0, 0
    for i = 1, #pages do
        local base = (pages[i] - 1) * 12
        for b = 1, 12 do
            local slot = base + b
            local want = d.slots[slot]
            local kind, cur = ReadSlot(slot)
            if kind == "secret" then
                skipped = skipped + 1
            elseif want then
                local target = Resolve(want)
                if target then
                    if (kind == "spell" and Holds(cur, target)) or Place(slot, target) then
                        placed = placed + 1
                    else
                        skipped = skipped + 1
                    end
                elseif kind == "empty" or Clear(slot) then
                    waiting = waiting + 1   -- emptied: the spell is placed once learned
                else
                    skipped = skipped + 1
                end
            elseif kind ~= "empty" then
                if Clear(slot) then cleared = cleared + 1 else skipped = skipped + 1 end
            end
        end
    end
    return placed, cleared, waiting, skipped
end

local pendingNew = {}   -- stored spell -> the spell Auto Populate will place
-- stored spell -> true: a higher rank of a spell known before (WoW Forever),
-- placed only over a lower rank and never on an empty button, so a button
-- the player emptied by hand stays empty.
local pendingUp = {}

local function DropPending()
    wipe(pendingNew)
    wipe(pendingUp)
end

--- Places the bar spells on the pages of the ticked bars ({ [barKey] = true }):
--- every page with at least one spell ends up exactly as built, its empty
--- buttons cleared; a spell not known yet empties its button and waits.
--- Returns placed, cleared, waiting, skipped, or nil and a reason: "nodata",
--- "nobars", "queued" (in combat: it runs when combat ends), "cursor" (the
--- cursor holds something), "error".
function P.Run(set)
    if type(set) ~= "table" then return nil, "nobars" end
    local d = P.Data()
    if not d then return nil, "nodata" end
    local pageSet = P.PagesFor(set)
    if next(pageSet) == nil then return nil, "nobars" end
    if InCombatLockdown() then
        local copy = CopySet(set)
        ns.CombatQueue.Defer("Populate", function()
            local placed, why = P.Run(copy)
            if not placed and why == "cursor" then
                EllesmereUI.PrintError(EllesmereUI.L("Put down what your cursor holds first."))
            end
        end)
        Say(EllesmereUI.L("Your action bars will be filled when combat ends."))
        return nil, "queued"
    end
    if GetCursorInfo() then return nil, "cursor" end

    bookGen = bookGen + 1
    -- Read by Action Bars' cursor handler (EUI_ActionBars_Setup.lua): these
    -- pickups are no drag. Cleared even when the loop raises.
    ns._eabScriptedPickup = true
    local ok, placed, cleared, waiting, skipped = pcall(RunLoop, d, SortedPages(pageSet))
    ns._eabScriptedPickup = nil
    if not ok then
        geterrorhandler()(placed)
        return nil, "error"
    end

    local st = SpecState(d.key, true)
    if st then
        st.bars = CopySet(set)
        Baseline(st, d)
        st.pushedOn = nil   -- the pages are as built: none of the game's copies sits on a waiting button
    end
    local mark = ActiveMark()
    if mark then MarkSeen(mark) end
    DropPending()
    Say(EllesmereUI.Lf("Action bar spells: %1$d placed, %2$d buttons emptied, %3$d waiting to be learned.", placed, cleared, waiting))
    if skipped > 0 then
        EllesmereUI.PrintError(EllesmereUI.Lf("%d action buttons could not be changed.", skipped))
    end
    P.Sync()
    return placed, cleared, waiting, skipped
end

-------------------------------------------------------------------------------
--  Auto Populate
-------------------------------------------------------------------------------
local shell, flusher         -- taken from the module's shell pool on first need
local reg = {}               -- event -> registered on shell
local learnArmed, specWatch = false, false
local waitBook = false       -- no check before the next SPELLS_CHANGED (login, spec or profile change)
local learnedFlag = false    -- a spell was learned since the last check: the gate is skipped
local checkDeferred = false
local gateLines, gateItems, gateKnownN, gateKnownSum = -1, -1, -1, -1
local placedCount = {}
-- Where the last Auto Populate placement that placed anything put each spell
-- (slot -> spell; placedSlot is the one being filled): the game's pushed copy
-- of such a spell, while that button still holds it, comes off.
local recentSlot, placedSlot = {}, {}
-- The game's pushed copies (slot -> spell). A copy is examined by the first
-- check out of combat after its push, so one pushed in a long fight is
-- examined when the fight ends; one Auto Populate placed (hit) is followed
-- until its slot changes (the game's fly-in lands) or the profile or spec
-- changes.
local pushedSpell, pushedHit, pushedN = {}, {}, 0
-- The names of the data's stored spells and of their WoW Forever alias rank,
-- read once per data table: only a learned spell of one of these names skips
-- the gate.
local learnNames, learnNamesOf = {}, nil
local syncProf, syncAbs, syncKey
local OnEvent

local function SetEvent(event, on, unit)
    on = on and true or false
    if (reg[event] == true) == on then return end
    if on then
        if not shell then
            shell = ns.TakeShell()
            shell:SetScript("OnEvent", function(_, ev, ...) OnEvent(ev, ...) end)
        end
        if unit then shell:RegisterUnitEvent(event, unit) else shell:RegisterEvent(event) end
        reg[event] = true
    else
        if shell then shell:UnregisterEvent(event) end
        reg[event] = nil
    end
end

local function ResetGate()
    gateLines, gateItems, gateKnownN, gateKnownSum = -1, -1, -1, -1
end

-- Whether the spellbook's item count or the builder spells known by ID moved
-- since the last check (a learned spell or talent moves one of them); nil
-- while the spellbook is not loaded.
local function GateChanged(d)
    local lines = Plain(C_SpellBook.GetNumSpellBookSkillLines()) or 0
    if lines == 0 then return nil end
    local items = 0
    for line = 1, lines do
        local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
        items = items + (li and Plain(li.numSpellBookItems) or 0)
    end
    local n, sum = 0, 0
    local spells = d.spells
    for i = 1, #spells do
        if KnownByID(spells[i]) then
            n = n + 1
            sum = sum + spells[i]
        end
    end
    if lines == gateLines and items == gateItems and n == gateKnownN and sum == gateKnownSum then return false end
    gateLines, gateItems, gateKnownN, gateKnownSum = lines, items, n, sum
    return true
end

-- The builder spells whose resolved spell changed since the last check. A
-- spell that became known is queued to fill its empty builder buttons; a
-- higher rank of one known before (WoW Forever) only to replace a lower rank,
-- so a button the player emptied by hand stays empty. On retail the other
-- spell of a known spell's name (a talent choice swapped) is not placed: the
-- buttons keep what they hold.
local function FindNew(d, st)
    local known = st.known
    if type(known) ~= "table" then
        known = {}
        st.known = known
    end
    local spells = d.spells
    for i = 1, #spells do
        local s = spells[i]
        local r = Resolve(s) or false
        local was = known[s]
        if was == nil then
            known[s] = r              -- first seen: recorded, not placed
        elseif r ~= was then
            known[s] = r
            if not r then
                pendingNew[s], pendingUp[s] = nil, nil
            elseif not was then
                pendingNew[s], pendingUp[s] = r, nil
            elseif pendingNew[s] ~= nil then
                pendingNew[s] = r     -- not placed yet: keeps how it is placed
            elseif IS_FOREVER then
                pendingNew[s], pendingUp[s] = r, true
            end
        end
    end
end

-- The game's own copy of a spell that fell on a builder button whose spell
-- the character did not know (the button waited) on a populated page:
-- remembered per spec (the roster's pushedOn: slot -> the game's spell), so
-- the builder's spell goes over it once learned. Until then the game's spell
-- stays on the bars. Runs before the check moves st.known, so a spell learned
-- in the same moment still reads as waited for.
local function NoteWaiting(d, st)
    if type(st.bars) ~= "table" then return end
    local pages = P.PagesFor(st.bars)
    local known = type(st.known) == "table" and st.known or nil
    for slot, pid in pairs(pushedSpell) do
        local want = d.slots[slot]
        if want and pages[floor((slot - 1) / 12) + 1] and not SameSpell(want, pid)
           and (not (known and known[want]) or not Resolve(want)) then
            local on = st.pushedOn
            if type(on) ~= "table" then
                on = {}
                st.pushedOn = on
            end
            on[slot] = pid
        end
    end
end

-- Fills an empty slot, one that still holds the game's own copy noted while
-- the slot waited (on), or on WoW Forever one holding a lower rank of the
-- spell; anything else on the slot is the player's and stays. A higher rank
-- of a spell known before fills no empty slot. A note whose slot no longer
-- holds the game's copy is dropped.
local function PlaceLoop(d, pages, on)
    for i = 1, #pages do
        local base = (pages[i] - 1) * 12
        for b = 1, 12 do
            local slot = base + b
            local want = d.slots[slot]
            local target = want and pendingNew[want]
            if target then
                local kind, cur = ReadSlot(slot)
                local noted = on and on[slot]
                local theirs = noted and kind == "spell" and SameSpell(cur, noted)
                local fill
                if kind == "empty" then
                    fill = not pendingUp[want]
                elseif theirs then
                    fill = not Holds(cur, target)
                elseif IS_FOREVER and kind == "spell" then
                    fill = not Holds(cur, target) and SameFamily(cur, target) and not TopRank(cur)
                end
                if fill and Place(slot, target) then
                    placedCount[target] = (placedCount[target] or 0) + 1
                    placedSlot[slot] = target
                    theirs = false
                end
                if noted and not theirs and kind ~= "secret" then on[slot] = nil end
            end
        end
    end
end

local function PlaceNew(d, st)
    wipe(placedCount)
    wipe(placedSlot)
    local pages = SortedPages(P.PagesFor(st.bars))
    local on = type(st.pushedOn) == "table" and st.pushedOn or nil
    ns._eabScriptedPickup = true
    local ok, err = pcall(PlaceLoop, d, pages, on)
    ns._eabScriptedPickup = nil
    if on and next(on) == nil then st.pushedOn = nil end
    DropPending()
    if not ok then
        geterrorhandler()(err)
        return
    end
    -- A placement that put nothing on the bars keeps the last one's record.
    if next(placedSlot) ~= nil then recentSlot, placedSlot = placedSlot, recentSlot end
    for id, n in pairs(placedCount) do
        local name = Plain(C_Spell.GetSpellName(id), "string")
        local link = Plain(C_Spell.GetSpellLink(id), "string") or name or "?"
        if n == 1 then
            Say(EllesmereUI.Lf("Auto Populate placed %s on 1 action button.", link))
        else
            Say(EllesmereUI.Lf("Auto Populate placed %1$s on %2$d action buttons.", link, n))
        end
    end
end

-- The game's own copy of a newly learned spell (SPELL_PUSHED_TO_ACTIONBAR:
-- its first free slot, 0 under WoW Forever's Gamepad interface style).
local function RecordPush(spellID, slot)
    spellID, slot = Plain(spellID), Plain(slot)
    if not (spellID and slot) or slot < 1 or slot > MAX_SLOT then return end
    if pushedSpell[slot] == nil then
        if pushedN >= MAX_RECORDS then return end
        pushedN = pushedN + 1
    end
    pushedSpell[slot], pushedHit[slot] = spellID, nil
end

local function DropPush(slot)
    if pushedSpell[slot] == nil then return end
    pushedSpell[slot], pushedHit[slot] = nil, nil
    pushedN = pushedN - 1
end

-- Whether the last Auto Populate placement put the pushed spell on a builder
-- button that still holds it (a button the player emptied since claims
-- nothing: the game's copy is then the player's only one).
local function Claimed(pid)
    for slot, id in pairs(recentSlot) do
        if SameSpell(id, pid) then
            local kind, cur = ReadSlot(slot)
            if kind == "spell" and SameSpell(cur, pid) then return true end
        end
    end
    return false
end

-- A copy of a spell Auto Populate placed comes off, unless the profile wants
-- that spell on that very slot; a copy of any other spell is the game's (on a
-- button that waited it stays until that button's spell is learned: see
-- NoteWaiting). A slot still empty waits for the game's fly-in to land
-- (ACTIONBAR_SLOT_CHANGED). on: the spec's noted copies, or nil.
local function PushedLoop(d, on)
    for slot, pid in pairs(pushedSpell) do
        if not (pushedHit[slot] or Claimed(pid)) then
            DropPush(slot)
        else
            pushedHit[slot] = true
            local want = d.slots[slot]
            local wanted = want and Resolve(want)
            if wanted and SameSpell(wanted, pid) then
                DropPush(slot)
            else
                local kind, cur = ReadSlot(slot)
                if kind == "spell" and SameSpell(cur, pid) then
                    DropPush(slot)
                    Clear(slot)
                    if on then on[slot] = nil end
                elseif kind ~= "empty" then
                    DropPush(slot)
                end
            end
        end
    end
end

local function EvalPushed(d, st)
    local on = type(st.pushedOn) == "table" and st.pushedOn or nil
    ns._eabScriptedPickup = true
    local ok, err = pcall(PushedLoop, d, on)
    ns._eabScriptedPickup = nil
    if not ok then geterrorhandler()(err) end
    if on and next(on) == nil then st.pushedOn = nil end
    SetEvent("ACTIONBAR_SLOT_CHANGED", pushedN > 0)
end

local function RunCheck(self)
    self:Hide()
    P.Check()
end

local function AfterCombat()
    checkDeferred = false
    P.RequestCheck()
end

--- One check on the next frame for every request of this one; after combat
--- when in it.
function P.RequestCheck()
    if not learnArmed then return end
    if InCombatLockdown() then
        if not checkDeferred then
            checkDeferred = true
            ns.CombatQueue.Defer("PopulateAuto", AfterCombat)
        end
        return
    end
    if not flusher then
        flusher = ns.TakeShell()
        flusher:Hide()
        flusher:SetScript("OnUpdate", RunCheck)
    end
    flusher:Show()
end

--- Places the builder spells that became known since the last check (out of
--- combat, with an empty cursor), then deals with the game's pushed copies.
function P.Check()
    if flusher then flusher:Hide() end
    if not learnArmed then return end
    if InCombatLockdown() then
        P.RequestCheck()
        return
    end
    local d = P.Data()
    local st = d and SpecState(d.key, false)
    if not st then return end
    bookGen = bookGen + 1
    if pushedN > 0 then NoteWaiting(d, st) end
    if not waitBook then
        local changed = GateChanged(d)
        if changed or (changed ~= nil and learnedFlag) then
            learnedFlag = false
            FindNew(d, st)
        end
    end
    if next(pendingNew) ~= nil then
        if GetCursorInfo() then
            SetEvent("CURSOR_CHANGED", true)
            return
        end
        SetEvent("CURSOR_CHANGED", false)
        PlaceNew(d, st)
    end
    if pushedN > 0 then EvalPushed(d, st) end
end

-- Whether a learned spell carries the name of one of the data's stored
-- spells or of their WoW Forever alias rank (an unreadable one counts): a
-- higher rank can leave the gate's counts as they were, any other spell that
-- matters moves them.
local function LearnsStored(id)
    id = Plain(id)
    local name = id and Plain(C_Spell.GetSpellName(id), "string")
    if not name then return true end
    local d = P.Data()
    if not d then return false end
    if learnNamesOf ~= d then
        learnNamesOf = d
        wipe(learnNames)
        local spells = d.spells
        for i = 1, #spells do
            local s = spells[i]
            local n = Plain(C_Spell.GetSpellName(s), "string")
            if n then learnNames[n] = true end
            n = ALIAS[s] and Plain(C_Spell.GetSpellName(ALIAS[s]), "string")
            if n then learnNames[n] = true end
        end
    end
    return learnNames[name] == true
end

OnEvent = function(event, a, b)
    if event == "SPELLS_CHANGED" then
        waitBook = false
        P.RequestCheck()
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
        if LearnsStored(a) then learnedFlag = true end
        P.RequestCheck()
    elseif event == "SPELL_PUSHED_TO_ACTIONBAR" then
        RecordPush(a, b)
        P.RequestCheck()
    elseif event == "CURSOR_CHANGED" then
        if not ns._eabScriptedPickup and not GetCursorInfo() then P.RequestCheck() end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        if not issecretvalue(a) and a ~= nil and pushedSpell[a] ~= nil then P.RequestCheck() end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        P.Sync()
    end
end

-- Retail: whether any spec of this character has Auto Populate on with bar
-- spells in abs (a spec change must arm that spec).
local function AnyAuto(abs)
    local r = Roster(false)
    if not r then return false end
    for key, st in pairs(r) do
        if type(key) == "string" and type(st) == "table" and st.auto == true
           and key:match("^%d+$") and SpecTable(abs, key) then
            return true
        end
    end
    return false
end

local function DropWork()
    DropPending()
    wipe(recentSlot)
    for slot in pairs(pushedSpell) do DropPush(slot) end
    learnedFlag = false
    if flusher then flusher:Hide() end
end

--- Matches the events to the active profile, the spec and the roster; run at
--- every Action Bars apply, a spec change, a Populate and a toggle. A profile
--- without bar spells returns after two table reads.
function P.Sync()
    local prof = ActiveProfile()
    local abs = ActiveABSpells(prof)
    if not abs and not syncAbs and not learnArmed and not specWatch then
        syncProf = prof
        return
    end
    local key = abs and SpecKeyFor(abs) or nil
    local changed = prof ~= syncProf or abs ~= syncAbs or key ~= syncKey
    if changed then
        syncProf, syncAbs, syncKey = prof, abs, key
        memoProf, memoAbs, memoKey, memoData = nil, nil, nil, nil
        DropWork()
        local picker = ns.PopulatePicker
        if picker and picker.IsOpen and picker.IsOpen() then picker.Close() end
    end
    local st = key and SpecState(key, false)
    local armed = st ~= nil and st.auto == true and type(st.bars) == "table" and next(st.bars) ~= nil
        and P.Data() ~= nil
    if armed and (changed or not learnArmed) then waitBook = true end
    if not armed then DropWork() end
    learnArmed = armed
    specWatch = not IS_FOREVER and abs ~= nil and AnyAuto(abs)
    SetEvent("SPELLS_CHANGED", armed)
    SetEvent("LEARNED_SPELL_IN_SKILL_LINE", armed)
    SetEvent("SPELL_PUSHED_TO_ACTIONBAR", armed)
    SetEvent("CURSOR_CHANGED", armed and next(pendingNew) ~= nil)
    SetEvent("ACTIONBAR_SLOT_CHANGED", armed and pushedN > 0)
    SetEvent("PLAYER_SPECIALIZATION_CHANGED", specWatch, "player")
    ResetGate()
end

--- Turns Auto Populate on or off for this spec; returns the state now. On
--- needs bar spells and a readable roster, and places only spells learned
--- from then on.
function P.SetAuto(on)
    local d = P.Data()
    if on then
        local st = d and SpecState(d.key, true)
        if not st then return false end
        st.auto = true
        bookGen = bookGen + 1
        Baseline(st, d)
    else
        local st = d and SpecState(d.key, false)
        if st then st.auto = nil end
    end
    P.Sync()
    return P.Auto()
end

-------------------------------------------------------------------------------
--  The popup after an import
-------------------------------------------------------------------------------
local promptShown

--- Marks the active profile's import as answered (Not Now).
function P.Dismiss()
    local mark = ActiveMark()
    if mark then MarkSeen(mark) end
end

--- After the reload of an import that brought bar spells for this character:
--- Choose Bars / Not Now, once per import per character. Waits for combat.
function P.Prompt()
    if promptShown then return false end
    local mark = ActiveMark()
    if not mark or not P.HasData() then return false end
    local r = Roster(true)
    if not r or (type(r.seen) == "table" and r.seen[mark]) then return false end
    if EllesmereUI._unlockModeActive then return false end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("PopulatePrompt", P.Prompt)
        return false
    end
    promptShown = true
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Action Bar Spells"),
        message = EllesmereUI.L("This profile includes action bar spells."),
        confirmText = EllesmereUI.L("Choose Bars"),
        cancelText = EllesmereUI.L("Not Now"),
        -- A view that refuses to open (a vehicle, Edit Mode, every bar off)
        -- leaves the import unanswered: the popup asks again at the next login.
        onConfirm = function()
            local picker = ns.PopulatePicker
            if not (picker and picker.Open) or picker.Open() then MarkSeen(mark) end
        end,
        -- Not Now, Escape and a click outside.
        onCancel = function() MarkSeen(mark) end,
    })
    return true
end

-------------------------------------------------------------------------------
--  Boot: after Action Bars' setup at login, then at every Action Bars apply
-------------------------------------------------------------------------------
local booted

function P.Boot()
    if booted then return end
    booted = true
    if type(_G._EAB_Apply) == "function" then
        hooksecurefunc("_EAB_Apply", function() P.Sync() end)
    end
    P.Sync()
    -- The popup reads the profile again only when Sync found bar spells.
    if syncAbs then P.Prompt() end
end

hooksecurefunc(EAB, "FinishSetup", function() P.Boot() end)

ns.Populate = P
