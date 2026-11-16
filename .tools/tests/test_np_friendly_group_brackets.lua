-- Stub harness: Nameplates, Show [] Around Group/Raid (EllesmereUINameplatesFriendly.lua).
-- Off by default. On, a friendly player's name takes blue brackets when the player is in your
-- party or your own raid subgroup, orange ones for the rest of your raid, in both friendly
-- modes (our own plate's name text, and the name composed onto Blizzard's name text).
-- A roster change can move a bracket. GROUP_ROSTER_UPDATE comes in bursts, so the event only
-- shows a hidden frame, and one pass on the next frame repaints the names whose bracket changed.
-- Driven here: the real bracket rule, composer, plate name painter and roster watcher, cut out
-- of the file by their first and last lines, over a model of the group and of the plates.
--   lua .tools/tests/test_np_friendly_group_brackets.lua        (from the repository root)
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

-------------------------------------------------------------------------------
-- The world: settings, the group, units, plates, frames
-------------------------------------------------------------------------------
local SECRET = {}
local profile = { friendlyGroupBrackets = false }
local mode, showLevel = "none", false
local G = { raid = false, pIdx = nil, subs = {} }      -- IsInRaid, your raid index, subgroup by raid index
local units = {}                                       -- token -> { name, player, me, party, ridx, guild, level }
local plates = {}                                      -- token -> Blizzard's base plate (name-only mode)
local ns = { pendingUnits = {} }
local friendlyPlates = {}                              -- token -> our own plate (full-plate mode)
local writes = 0                                       -- name text writes, both modes
local raidAsks, nameAsks = 0, 0                        -- bracket rule runs; names read (one per repaint)

local function NewFS()
    local fs = {}
    function fs:SetText(t) self.text = t; writes = writes + 1 end
    function fs:SetFormattedText(fmt, ...) self.text = fmt:format(...); writes = writes + 1 end
    function fs:SetWordWrap() end
    function fs:SetMaxLines() end
    return fs
end
local frames = {}
local function CreateFrame()
    local f = { shown = true, events = {}, scripts = {} }
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:SetScript(n, fn) self.scripts[n] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
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
local function hooksecurefunc(obj, name, fn)
    local orig = obj[name]
    obj[name] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end

local FriendlyFrame = { UpdateSubText = function() end }
local Kind, Attach = assert(loadstring(
    "local ns, FP, FriendlyFrame, friendlyPlates, CreateFrame, hooksecurefunc, EllesmereUI, C_NamePlate, GetBelowNameMode, ModeHasTitle, " ..
    "ModeHasGuild, GetTitledName, FriendlyNameFormat, FormatFriendlyName, ShowFriendlyLevel, FriendlyLevelText, GetSubTextColor, " ..
    "EnsureNameUnconstrained, IsNameOnlyMode, UnitExists, UnitCanAttack, UnitIsPlayer, UnitName, UnitIsUnit, GetGuildInfo, issecretvalue, " ..
    "IsInRaid, UnitInRaid, GetRaidRosterInfo, UnitInParty = ...\n" ..
    -- Name Color's Custom colour, which the composer asks for (none picked here)
    Cut(SRC, "local NameEsc = {}", "-- Name Format (friendlyNameFormat:", "the Custom colour's escape") ..
    Cut(SRC, 'local PARTY_BRACKET_OPEN  = ', "-- The player's name WITH their title as one string", "the bracket rule") ..
    Cut(SRC, 'local nameFSUnits = setmetatable({}, { __mode = "k" })', "-- Re-collapse every visible friendly player name", "the composer") ..
    Cut(SRC, "function FriendlyFrame:UpdateName()", "-- Below Name sub text (guild only", "the plate's name painter") ..
    "do\n" .. Cut(SRC, "    local groupEv, armed", "-- Live-apply a Subtitle Text setting change", "the roster watcher") ..
    "\nreturn GetUnitGroupBracketKind, AttachNameOnlyText", "=EllesmereUINameplatesFriendly.lua"))(
    ns, function() return profile end, FriendlyFrame, friendlyPlates, CreateFrame, hooksecurefunc,
    { WithSurname = function(name) return name end },
    { GetNamePlateForUnit = function(u) return plates[u] end },
    function() return mode end,
    function(m) return m == "title" or m == "both" end,
    function(m) return m == "guild" or m == "both" end,
    function() return nil end,
    function() return nil end,
    function(_, name) return name end,
    function() return showLevel end,
    function(u) return tostring(units[u].level or 60) end,
    function() return 0.8, 0.8, 0.8 end,
    function() end,
    function() return true end,
    function(u) return units[u] ~= nil end,
    function() return false end,
    function(u) return units[u] ~= nil and units[u].player == true end,
    function(u) nameAsks = nameAsks + 1; return units[u].name end,
    function(u) return units[u].me == true end,
    function(u) return units[u].guild end,
    function(v) return v == SECRET end,
    function() raidAsks = raidAsks + 1; return G.raid end,
    function(u) if u == "player" then return G.pIdx end return units[u] and units[u].ridx end,
    function(i) return "n", 0, G.subs[i] end,
    function(u) return units[u] ~= nil and units[u].party == true end)

local BLUE, ORANGE = "|cffaaaaff", "|cffff7f00"
local function Blue(name) return BLUE .. "[|r" .. name .. BLUE .. "]|r" end
local function Orange(name) return ORANGE .. "[|r" .. name .. ORANGE .. "]|r" end

-- A friendly player on our own plate (full-plate mode) or on Blizzard's name text (name-only).
local function FullPlate(token, unit)
    units[token] = unit
    local plate = setmetatable({ unit = token, name = NewFS() }, { __index = FriendlyFrame })
    friendlyPlates[token] = plate
    plate:UpdateName()
    return plate
end
local function NameOnly(token, unit)
    units[token] = unit
    local base = { UnitFrame = { name = NewFS() } }
    plates[token], ns.pendingUnits[token] = base, base
    base.UnitFrame.name:SetText(unit.name)
    Attach(base.UnitFrame.name, token)
    return base.UnitFrame.name
end
local function Clear()
    for k in pairs(units) do units[k] = nil end
    for k in pairs(plates) do plates[k] = nil end
    for k in pairs(ns.pendingUnits) do ns.pendingUnits[k] = nil end
    for k in pairs(friendlyPlates) do friendlyPlates[k] = nil end
    G.raid, G.pIdx, G.subs = false, nil, {}
end

-------------------------------------------------------------------------------
-- 1. which bracket a unit takes
-------------------------------------------------------------------------------
do
    units.a = { name = "A", player = true }
    check(Kind("a") == nil, "a player outside your group gets a bracket")
    units.a.party = true
    check(Kind("a") == "party", "a party member is not party: " .. tostring(Kind("a")))
    units.me = { name = "Me", player = true, me = true, party = true }
    check(Kind("me") == nil, "your own name gets a bracket")
    check(Kind(nil) == nil, "no unit gets a bracket")
    -- a raid: you are index 3 in subgroup 2
    G.raid, G.pIdx, G.subs = true, 3, { [3] = 2, [4] = 2, [9] = 5 }
    units.b = { name = "B", player = true, ridx = 4, party = true }     -- your subgroup
    units.c = { name = "C", player = true, ridx = 9 }                   -- another subgroup
    units.d = { name = "D", player = true }                             -- not in the raid
    check(Kind("b") == "party", "a member of your raid subgroup is not party: " .. tostring(Kind("b")))
    check(Kind("c") == "raid", "a member of another subgroup is not raid: " .. tostring(Kind("c")))
    check(Kind("d") == nil, "a player outside the raid gets a bracket")
    -- the subgroups decide, not the party flag, while they can be read
    units.c.party = true
    check(Kind("c") == "raid", "the party flag wins over a readable subgroup")
    units.c.party = nil
    -- values the game keeps secret are never compared: the party test decides
    units.e = { name = "E", player = true, ridx = SECRET, party = true }
    units.f = { name = "F", player = true, ridx = SECRET }
    check(Kind("e") == "party" and Kind("f") == nil, "a secret raid index: " .. tostring(Kind("e")) .. " / " .. tostring(Kind("f")))
    G.subs[9] = SECRET
    check(Kind("c") == "raid", "a secret subgroup of a raid member outside your party is not raid")
    G.subs[4] = SECRET
    check(Kind("b") == "party", "a secret subgroup of a member of your party is not party")
    G.subs[4], G.subs[9], G.subs[3] = 2, 5, SECRET
    check(Kind("b") == "party" and Kind("c") == "raid", "your own subgroup secret: " .. tostring(Kind("b")) .. " / " .. tostring(Kind("c")))
    G.subs[3], G.pIdx = 2, SECRET
    check(Kind("b") == "party" and Kind("c") == "raid", "your own raid index secret: " .. tostring(Kind("b")) .. " / " .. tostring(Kind("c")))
    G.pIdx = nil
    check(Kind("b") == "party" and Kind("c") == "raid", "your own raid index unknown: " .. tostring(Kind("b")) .. " / " .. tostring(Kind("c")))
    Clear()
end

-------------------------------------------------------------------------------
-- 2. the names, in both modes
-------------------------------------------------------------------------------
do
    -- off (the default): plain names, and the watcher builds nothing
    local p = FullPlate("np1", { name = "Alice", player = true, party = true })
    local n = NameOnly("np2", { name = "Bob", player = true, party = true })
    check(p.name.text == "Alice" and n.text == "Bob", "off: a name has brackets (" .. tostring(p.name.text) .. ", " .. tostring(n.text) .. ")")
    ns.NP_FriendlyGroupWatch()
    check(#frames == 0, "off: the roster watcher built a frame")
    Clear()

    profile.friendlyGroupBrackets = true
    G.raid, G.pIdx, G.subs = true, 1, { [1] = 1, [2] = 1, [3] = 4 }
    p = FullPlate("np1", { name = "Alice", player = true, ridx = 2, party = true })
    local q = FullPlate("np3", { name = "Cid", player = true, ridx = 3 })
    local r = FullPlate("np5", { name = "Stray", player = true })
    local pet = FullPlate("np7", { name = "Wolf", player = false, party = true })
    check(p.name.text == Blue("Alice"), "full plate, your subgroup: " .. tostring(p.name.text))
    check(q.name.text == Orange("Cid"), "full plate, another subgroup: " .. tostring(q.name.text))
    check(r.name.text == "Stray", "full plate, outside the raid: " .. tostring(r.name.text))
    check(pet.name.text == "Wolf", "a pet's name has brackets: " .. tostring(pet.name.text))
    n = NameOnly("np2", { name = "Bob", player = true, ridx = 2, party = true })
    local o = NameOnly("np4", { name = "Dee", player = true, ridx = 3 })
    local s = NameOnly("np6", { name = "Loner", player = true })
    check(n.text == Blue("Bob"), "name only, your subgroup: " .. tostring(n.text))
    check(o.text == Orange("Dee"), "name only, another subgroup: " .. tostring(o.text))
    check(s.text == "Loner", "name only, outside the raid: " .. tostring(s.text))
    n:SetText("Bob")
    check(n.text == Blue("Bob"), "name only: Blizzard's own name write loses the brackets: " .. tostring(n.text))
    -- with Show Level the level stays outside the brackets; a guild line stays under the name
    showLevel = true
    p:UpdateName()
    n:SetText("Bob")
    check(p.name.text == "60 | " .. Blue("Alice"), "full plate with Show Level: " .. tostring(p.name.text))
    check(n.text == "60 | " .. Blue("Bob"), "name only with Show Level: " .. tostring(n.text))
    showLevel, mode = false, "guild"
    units.np4.guild = "Owls"
    o:SetText("Dee")
    check(o.text == Orange("Dee") .. "\n|cffcccccc<Owls>|r", "name only with a guild line: " .. tostring(o.text))
    mode = "none"
    Clear()
end

-------------------------------------------------------------------------------
-- 3. a roster change: one pass per burst, only the names it moved
-------------------------------------------------------------------------------
do
    ns.NP_FriendlyGroupWatch()
    check(#frames == 1, "on: the roster watcher built " .. #frames .. " frames")
    local ev = frames[1]
    check(ev ~= nil and ev.events.GROUP_ROSTER_UPDATE == true, "on: the roster event is not registered")
    check(ev ~= nil and ev.shown == false, "the watcher's frame is not hidden while idle (its update would run every frame)")
    ns.NP_FriendlyGroupWatch()
    check(#frames == 1, "asking again built another frame")

    -- a raid of forty names on screen: twenty of our plates, twenty name-only texts
    G.raid, G.pIdx, G.subs = true, 1, { [1] = 1 }
    local full, only = {}, {}
    for i = 1, 20 do
        G.subs[i + 1], G.subs[i + 21] = (i <= 4) and 1 or 3, (i <= 4) and 1 or 3
        full[i] = FullPlate("f" .. i, { name = "F" .. i, player = true, ridx = i + 1, party = i <= 4 })
        only[i] = NameOnly("n" .. i, { name = "N" .. i, player = true, ridx = i + 21, party = i <= 4 })
    end
    check(full[1].name.text == Blue("F1") and full[9].name.text == Orange("F9") and only[9].text == Orange("N9"), "the raid's names are not bracketed")
    local pet = FullPlate("pet1", { name = "Wolf", player = false, party = true })

    -- nothing moved: a burst of roster events repaints nothing
    writes = 0
    Tick()
    check(writes == 0, "a frame with no roster event repainted " .. writes .. " names")
    raidAsks, nameAsks = 0, 0
    for _ = 1, 5 do Fire("GROUP_ROSTER_UPDATE") end
    check(writes == 0 and raidAsks == 0, "the roster event works at once (" .. writes .. " writes, " .. raidAsks .. " bracket checks before the next frame)")
    check(ev.shown == true, "a roster event does not ask for a pass")
    Tick()
    check(writes == 0, "a roster burst that moved nobody repainted " .. writes .. " names")
    check(raidAsks == 40, "five roster events made " .. raidAsks .. " bracket checks over forty names (one pass is 40)")
    check(nameAsks == 0, "a roster burst that moved nobody recomposed " .. nameAsks .. " names")
    check(pet.name.text == "Wolf", "a pet took brackets in the roster pass")
    check(ev.shown == false, "the watcher keeps running after its pass")

    -- one member of each mode moves into your subgroup: exactly those two names repaint, once
    G.subs[10], units.f9.party = 1, true
    G.subs[30], units.n9.party = 1, true
    writes = 0
    for _ = 1, 5 do Fire("GROUP_ROSTER_UPDATE") end
    Tick()
    check(full[9].name.text == Blue("F9"), "a member moved into your subgroup keeps the old bracket (our plate): " .. tostring(full[9].name.text))
    check(only[9].text == Blue("N9"), "a member moved into your subgroup keeps the old bracket (name only): " .. tostring(only[9].text))
    check(writes == 2, "five roster events over forty names made " .. writes .. " name writes (two names changed)")
    Tick()
    check(writes == 2, "the pass ran again on the next frame")
    -- the same state again: the names remember their bracket
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    check(writes == 2, "an unchanged roster repainted " .. (writes - 2) .. " names")

    -- a member leaves the raid: the brackets go
    units.f2.ridx, units.f2.party = nil, nil
    units.n2.ridx, units.n2.party = nil, nil
    writes = 0
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    check(full[2].name.text == "F2" and only[2].text == "N2", "a member who left keeps brackets: " .. tostring(full[2].name.text) .. ", " .. tostring(only[2].text))
    check(writes == 2, "a member leaving repainted " .. writes .. " names")

    -- you move to subgroup 3: every name's bracket flips but the two outside the raid
    G.subs[1] = 3
    for i = 1, 20 do
        if units["f" .. i].ridx then units["f" .. i].party = G.subs[i + 1] == 3 end
        if units["n" .. i].ridx then units["n" .. i].party = G.subs[i + 21] == 3 end
    end
    writes = 0
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    check(full[1].name.text == Orange("F1") and full[12].name.text == Blue("F12") and only[12].text == Blue("N12"), "your own subgroup move does not flip the brackets")
    check(writes == 38, "your own subgroup move repainted " .. writes .. " names, not the 38 it flipped")

    -- off: the event goes, and a pass that was asked for is dropped
    Fire("GROUP_ROSTER_UPDATE")
    profile.friendlyGroupBrackets = false
    ns.NP_FriendlyGroupWatch()
    check(next(ev.events) == nil, "off: the roster event stays registered")
    check(ev.shown == false, "off: the pending pass still runs")
    writes = 0
    Fire("GROUP_ROSTER_UPDATE")
    Tick()
    check(writes == 0, "off: a roster event still repaints")
    -- on again: the same frame, registered again
    profile.friendlyGroupBrackets = true
    ns.NP_FriendlyGroupWatch()
    check(#frames == 1 and ev.events.GROUP_ROSTER_UPDATE == true and ev.shown == false, "on again: not the same hidden frame, registered")
    profile.friendlyGroupBrackets = false
    ns.NP_FriendlyGroupWatch()
    Clear()
end

-------------------------------------------------------------------------------
-- 4. the option
-------------------------------------------------------------------------------
do
    local OPT = ReadSource("EllesmereUIOptions/Nameplates_Options/FriendlyPage_Options.lua")
    -- a row of the Friendly Nameplate Style cog (the cog's second), not a row of the page
    local row = Cut(OPT, '        { type="toggle", label="Show [] Around Group/Raid",', "          end }", "the option's row")
    local tip = row:match('tooltip="([^"]+)"')
    check(tip ~= nil and tip:find("instances", 1, true) ~= nil, "the tooltip does not say that it does not show inside instances")
    check(row:find("disabled=friendlyPlayersOff, disabledTooltip=STYLE_REQ, rawTooltip=true", 1, true) ~= nil,
        "the row's greyed tooltip is not the Friendly Nameplate Style requirement, shown as written")
    check(OPT:find("            rows = { npSizeRow, bracketsRow },", 1, true) ~= nil and not OPT:find('text="Show [] Around Group/Raid"', 1, true),
        "the option is not the second row of the Friendly Nameplate Style cog, or is still a row of the page")
    check(row:find('DBVal("friendlyGroupBrackets") == true', 1, true) ~= nil, "the toggle does not read as off while unset")
    local MAIN = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")
    check(MAIN:find("    friendlyGroupBrackets = false,", 1, true) ~= nil, "the option is not off by default")
    -- both texts are translated in every language
    for _, code in ipairs({ "deDE", "esES", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local L = ReadSource("EllesmereUILocales/" .. code .. ".lua")
        check(L:find('L["Show [] Around Group/Raid"]', 1, true) ~= nil, code .. ": the option's name is not translated")
        check(tip ~= nil and L:find('L["' .. tip .. '"]', 1, true) ~= nil, code .. ": the option's tooltip is not translated")
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_friendly_group_brackets (%d checks)"):format(count))
