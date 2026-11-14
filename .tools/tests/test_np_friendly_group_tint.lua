-- Stub harness: Nameplates, the WoW Forever style's group tint on friendly player bars
-- (EllesmereUINameplatesFriendly.lua). Under the WoW Forever nameplate style, with Class Colored
-- Health Bar off, a friendly player in your party or raid takes the stock plate's group tint
-- (the engine's selection colour) in place of the Health Bar Color; everyone else keeps that
-- colour. Rules checked here:
--   - the tint shows only under that style and only with Class Colored Health Bar off; under
--     any other style, or with the class colour on, the group is not even asked;
--   - the raid index can read secret: only its type is asked, and the answer is a plain yes / no;
--   - a roster change repaints only the bars whose group state changed, once per burst of
--     roster events (the watcher Show [] Around Group/Raid uses), and the roster event is
--     registered only while the tint or the brackets can show;
--   - the roster event no longer repaints every friendly plate.
-- Driven here: the real painter, colour refresh and roster watcher, cut out of the file by
-- their first and last lines, over a model of the group and of the plates.
--   lua .tools/tests/test_np_friendly_group_tint.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")
local EVENTS = ReadSource("EllesmereUINameplates/EUI_Nameplates_Events.lua")
assert(loadstring(SRC, "=EllesmereUINameplatesFriendly.lua"), "the friendly nameplates file does not compile")
assert(loadstring(EVENTS, "=EUI_Nameplates_Events.lua"), "the events file does not compile")

-------------------------------------------------------------------------------
-- The world: the style, the settings, the group, the plates, frames
-------------------------------------------------------------------------------
-- A raid index the game keeps secret: a number to type(), and nothing else may be asked of it.
local SECRET = {}
local function Type(v)
    if v == SECRET then return "number" end
    return type(v)
end
local forever = true
local profile = { classColorFriendly = false, friendlyBarColor = { r = 0.1, g = 0.9, b = 0.2 } }
local units = {}                                   -- token -> { player, party, ridx, class, kind }
local friendlyPlates = {}
local asks = { party = 0, raid = 0, sel = 0, kind = 0 }
local selExtended = true                           -- every selection colour was asked with the extended set
local BLUE = { 0.67, 0.67, 1 }                     -- the selection colour of a group member
local GREEN = { 0.1, 0.9, 0.2 }                    -- the Health Bar Color
local NPC = { 0.2, 0.3, 0.4 }

local function NewPlate(token, unit)
    units[token] = unit
    local plate = { barWrites = 0, nameWrites = 0, nameUpdates = 0 }
    plate.health = { SetStatusBarColor = function(_, r, g, b) plate.bar = { r, g, b }; plate.barWrites = plate.barWrites + 1 end }
    plate.name = { SetTextColor = function(_, r, g, b) plate.nameColor = { r, g, b }; plate.nameWrites = plate.nameWrites + 1 end }
    function plate:UpdateName() self.nameUpdates = self.nameUpdates + 1; self._grpKind = units[token].kind end
    friendlyPlates[token] = plate
    return plate
end
local function Is(c, want) return c ~= nil and c[1] == want[1] and c[2] == want[2] and c[3] == want[3] end

local frames = {}
local function CreateFrame()
    local f = { shown = true, events = {}, scripts = {}, registered = 0 }
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:SetScript(n, fn) self.scripts[n] = fn end
    function f:RegisterEvent(e) self.events[e] = true; self.registered = self.registered + 1 end
    function f:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = f
    return f
end
local function Fire(event)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
    end
end
-- One rendered frame: OnUpdate runs on shown frames only.
local function Tick()
    for _, f in ipairs(frames) do
        if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
    end
end

local ns = { NP_Forever = function() return forever end, pendingUnits = {} }
-- Name Color's rule, as the painter asks it (the real one), and the Custom colour's default
assert(loadstring("local ns = ...\n" .. Cut(ReadSource("EllesmereUINameplates/EUI_Nameplates_CastState.lua"),
    "function ns.FriendlyNameClass(db, nameOnly)", "\n-- Value (1/0) of the class-colour CVar", "the name colour rule"),
    "=EUI_Nameplates_CastState.lua"))(ns)
ns.defaults = { friendlyNameColor = { r = 1, g = 1, b = 1 } }
local InMyGroup, Paint = assert(loadstring(
    "local ns, FP, friendlyPlates, CreateFrame, UnitIsPlayer, UnitInParty, UnitInRaid, UnitSelectionColor, ClassRGB, " ..
    "GetFriendlyNPCColor, GetUnitGroupBracketKind, ShowFriendlyGroupBrackets, UpdateNameOnlyText, nameFSUnits, nameFSText, type = ...\n" ..
    Cut(SRC, "-- Whether a unit is in your party or raid.", "--  Below Name sub text: data + rendering", "the painter") ..
    "\ndo\n" .. Cut(SRC, "    local groupEv, armed", "-- Live-apply a Subtitle Text setting change", "the roster watcher") ..
    Cut(SRC, "function ns.RefreshFriendlyColors(paletteChanged)", "-- Re-apply the full-plate friendly name text size", "the colour refresh") ..
    "\nreturn InMyGroup, PaintFriendlyColors", "=EllesmereUINameplatesFriendly.lua"))(
    ns, function() return profile end, friendlyPlates, CreateFrame,
    function(u) return units[u] ~= nil and units[u].player == true end,
    function(u) asks.party = asks.party + 1; return units[u] ~= nil and units[u].party == true end,
    function(u) asks.raid = asks.raid + 1; return units[u] and units[u].ridx or nil end,
    function(u, extended)
        asks.sel = asks.sel + 1
        if extended ~= true then selExtended = false end
        return BLUE[1], BLUE[2], BLUE[3], 1
    end,
    function(u)
        local c = units[u] and units[u].class
        if c then return true, c[1], c[2], c[3] end
        return false
    end,
    function() return NPC[1], NPC[2], NPC[3] end,
    function(u) asks.kind = asks.kind + 1; return units[u] and units[u].kind end,
    function() return profile.friendlyGroupBrackets == true end,
    function() end, {}, {}, Type)
check(type(InMyGroup) == "function" and type(Paint) == "function", "the group test or the painter is gone")

local function Clear()
    for k in pairs(units) do units[k] = nil end
    for k in pairs(friendlyPlates) do friendlyPlates[k] = nil end
end
local function ResetAsks() asks.party, asks.raid, asks.sel, asks.kind = 0, 0, 0, 0 end

-------------------------------------------------------------------------------
-- 1. who is in your group
-------------------------------------------------------------------------------
do
    units.a = { player = true, party = true }
    units.b = { player = true, ridx = 7 }
    units.c = { player = true, ridx = SECRET }
    units.d = { player = true }
    check(InMyGroup("a") == true, "a party member is not in your group: " .. tostring(InMyGroup("a")))
    check(InMyGroup("b") == true, "a raid member outside your party is not in your group: " .. tostring(InMyGroup("b")))
    check(InMyGroup("c") == true, "a raid member whose index is secret does not answer a plain yes: " .. tostring(InMyGroup("c")))
    check(InMyGroup("d") == false, "a stranger does not answer a plain no: " .. tostring(InMyGroup("d")))
    Clear()
end

-------------------------------------------------------------------------------
-- 2. the painter
-------------------------------------------------------------------------------
do
    local party = NewPlate("p", { player = true, party = true, class = { 0.9, 0.1, 0.1 } })
    local raid = NewPlate("r", { player = true, ridx = 12, class = { 0.9, 0.1, 0.1 } })
    local hid = NewPlate("h", { player = true, ridx = SECRET })
    local stray = NewPlate("s", { player = true, class = { 0.9, 0.1, 0.1 } })
    local pet = NewPlate("pet", { player = false, party = true })
    for token, plate in pairs(friendlyPlates) do Paint(plate, token, profile) end
    check(Is(party.bar, BLUE) and party._grpTint == true, "a party member's bar is not the group tint")
    check(Is(raid.bar, BLUE) and raid._grpTint == true, "a raid member's bar is not the group tint")
    check(Is(hid.bar, BLUE) and hid._grpTint == true, "a raid member with a secret index is not tinted")
    check(Is(stray.bar, GREEN) and stray._grpTint ~= true, "a player outside your group lost the Health Bar Color")
    check(Is(pet.bar, NPC) and Is(pet.nameColor, NPC) and pet._grpTint ~= true, "a group member's pet is not in the NPC colour")
    check(Is(party.nameColor, { 1, 1, 1 }) and Is(stray.nameColor, { 1, 1, 1 }), "the tint changed a name's colour")
    check(asks.sel == 3 and selExtended, "the tint is not the engine's extended selection colour, asked once per tinted bar")
    -- Class Colored Names: the name follows the class, the bar keeps the tint
    profile.friendlyNameClassColor = true
    Paint(party, "p", profile)
    check(Is(party.bar, BLUE) and Is(party.nameColor, { 0.9, 0.1, 0.1 }), "Class Colored Names: the bar or the name is off")
    profile.friendlyNameClassColor = nil
    -- a plate reused for a stranger forgets its tint
    units.p.party = nil
    Paint(party, "p", profile)
    check(Is(party.bar, GREEN) and party._grpTint ~= true, "a plate painted for a stranger still counts as tinted")
    units.p.party = true
    -- Class Colored Health Bar on: the class colour, and the group is not asked
    profile.classColorFriendly = true
    ResetAsks()
    Paint(party, "p", profile)
    check(Is(party.bar, { 0.9, 0.1, 0.1 }) and party._grpTint ~= true, "Class Colored Health Bar: a group member is not in the class colour")
    check(asks.party + asks.raid + asks.sel == 0, "Class Colored Health Bar: the group was asked")
    Paint(party, "p", nil)
    check(Is(party.bar, { 0.9, 0.1, 0.1 }), "no profile yet: not the class colour")
    profile.classColorFriendly = false
    -- any other style: the Health Bar Color for everyone, and the group is not asked
    forever = false
    ResetAsks()
    Paint(party, "p", profile)
    Paint(raid, "r", profile)
    check(Is(party.bar, GREEN) and Is(raid.bar, GREEN) and party._grpTint ~= true, "another style tints group members")
    check(asks.party + asks.raid + asks.sel == 0, "another style asked about the group")
    forever = true
    Clear()
end

-------------------------------------------------------------------------------
-- 3. the roster event is listened to only while the tint or the brackets can show
-------------------------------------------------------------------------------
local ev
do
    forever, profile.classColorFriendly = false, false
    ns.NP_FriendlyGroupWatch()
    check(#frames == 0, "another style: the roster watcher built a frame")
    forever, profile.classColorFriendly = true, true
    ns.NP_FriendlyGroupWatch()
    check(#frames == 0, "Class Colored Health Bar on: the roster watcher built a frame")
    profile.classColorFriendly = false
    ns.NP_FriendlyGroupWatch()
    ev = frames[1]
    check(#frames == 1 and ev.events.GROUP_ROSTER_UPDATE == true, "the tint can show: the roster event is not registered")
    check(ev ~= nil and ev.shown == false, "the watcher's frame is not hidden while idle (its update would run every frame)")
    ns.NP_FriendlyGroupWatch()
    check(#frames == 1 and ev.registered == 1, "asking again built a frame or registered again")
    -- Class Colored Health Bar turned on from the options (their path is the colour refresh):
    -- nothing to listen for, also when a pass was waiting for its frame
    Fire("GROUP_ROSTER_UPDATE")
    check(ev.shown == true, "a roster event did not ask for a pass")
    profile.classColorFriendly = true
    ns.RefreshFriendlyColors()
    check(next(ev.events) == nil and ev.shown == false, "Class Colored Health Bar on: the watcher still listens, or its frame stayed shown")
    profile.classColorFriendly = false
    ns.RefreshFriendlyColors()
    check(ev.events.GROUP_ROSTER_UPDATE == true and #frames == 1, "Class Colored Health Bar off again: the colour refresh did not arm the watcher")
    -- the brackets join: one registration, and a pass that was waiting stays
    Fire("GROUP_ROSTER_UPDATE")
    local before = ev.registered
    profile.friendlyGroupBrackets = true
    ns.NP_FriendlyGroupWatch()
    check(ev.registered == before and ev.shown == true and #frames == 1, "a second reason to listen registered again or dropped the waiting pass")
    Tick()
    profile.friendlyGroupBrackets = false
    ns.NP_FriendlyGroupWatch()
    check(ev.events.GROUP_ROSTER_UPDATE == true, "the brackets turned off took the tint's registration with them")
end

-------------------------------------------------------------------------------
-- 4. a roster change: one pass per burst, only the bars it moved
-------------------------------------------------------------------------------
do
    local plates = {}
    for i = 1, 10 do
        plates[i] = NewPlate("f" .. i, { player = true, party = i <= 3, ridx = (i == 4) and 9 or nil })
    end
    local pet = NewPlate("pet", { player = false, party = true })
    ns.RefreshFriendlyColors()
    check(Is(plates[1].bar, BLUE) and Is(plates[4].bar, BLUE) and Is(plates[5].bar, GREEN), "the colour refresh did not paint the group")
    local function Writes()
        local bars, names = 0, 0
        for _, plate in pairs(friendlyPlates) do bars, names = bars + plate.barWrites, names + plate.nameWrites end
        return bars, names
    end
    local function ResetWrites()
        for _, plate in pairs(friendlyPlates) do plate.barWrites, plate.nameWrites, plate.nameUpdates = 0, 0, 0 end
        ResetAsks()
    end
    -- nothing moved: a burst of roster events repaints nothing, in one pass
    ResetWrites()
    for _ = 1, 10 do Fire("GROUP_ROSTER_UPDATE") end
    check(Writes() == 0, "roster events painted before the next frame")
    Tick()
    local bars, names = Writes()
    check(bars == 0 and names == 0, "nothing moved, yet the pass repainted " .. bars .. " bars")
    check(asks.party == 10, "the pass asked about " .. asks.party .. " players' group, not once each for ten")
    check(asks.kind == 0, "the bracket rule ran with the brackets off")
    check(ev.shown == false, "the watcher's frame stayed shown after its pass")
    -- one joins, one leaves, one raid member drops out: exactly those three bars
    units.f7.party, units.f1.party, units.f4.ridx = true, false, nil
    ResetWrites()
    for _ = 1, 5 do Fire("GROUP_ROSTER_UPDATE") end
    Tick()
    bars = Writes()
    check(bars == 3, "three players changed group, the pass repainted " .. bars .. " bars")
    check(Is(plates[7].bar, BLUE) and plates[7]._grpTint == true, "the player who joined is not tinted")
    check(Is(plates[1].bar, GREEN) and plates[1]._grpTint ~= true and Is(plates[4].bar, GREEN), "a player who left kept the tint")
    check(plates[2].barWrites == 0 and plates[5].barWrites == 0 and pet.barWrites == 0, "a bar that did not move was repainted")
    -- a second burst, and a frame with no event: nothing
    ResetWrites()
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    Tick()
    check(Writes() == 0, "a burst after the change repainted bars again")
    -- the brackets on as well: both passes run, each on what it moved
    profile.friendlyGroupBrackets = true
    ns.NP_FriendlyGroupWatch()
    units.f2.kind, units.f9.party = "party", true
    ResetWrites()
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    bars = Writes()
    check(bars == 1 and Is(plates[9].bar, BLUE), "with the brackets on the tint pass repainted " .. bars .. " bars, not the one that moved")
    check(plates[2].nameUpdates == 1 and plates[9].nameUpdates == 0, "the bracket pass did not repaint just the name that moved")
    -- Class Colored Health Bar on, brackets still on: the roster pass leaves the bars alone
    profile.classColorFriendly = true
    ns.RefreshFriendlyColors()
    units.f10.party = true
    ResetWrites()
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    check(Writes() == 0 and asks.party + asks.raid == 0, "with the class colour on, a roster change repainted bars or asked about the group")
    profile.friendlyGroupBrackets, profile.classColorFriendly = false, false
    ns.RefreshFriendlyColors()
    check(Is(plates[10].bar, BLUE) and plates[10]._grpTint == true, "Class Colored Health Bar off again: the refresh did not bring the tint back")
    Clear()
end

-------------------------------------------------------------------------------
-- 5. the roster event no longer repaints every friendly plate, and secret values are typed first
-------------------------------------------------------------------------------
do
    check(not EVENTS:find("RefreshFriendlyColors", 1, true), "the nameplates' roster handler still repaints every friendly plate")
    local rule = Cut(SRC, "local function GetUnitGroupBracketKind(unit)", "-- The player's name WITH their title as one string", "the bracket rule")
    check(rule:find('if type(rIdx) == "number" and not issecretvalue(rIdx) then', 1, true)
        and rule:find('if type(pIdx) == "number" and not issecretvalue(pIdx) then', 1, true)
        and not rule:find("if rIdx and", 1, true) and not rule:find("if pIdx and", 1, true) and not rule:find("if uSub and", 1, true),
        "the bracket rule truth-tests a raid index or subgroup before asking its type")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_friendly_group_tint (%d checks)"):format(count))
